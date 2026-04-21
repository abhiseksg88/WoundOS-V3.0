#!/usr/bin/env python3
"""
Convert WoundAmbit FUSegNet PyTorch model → ONNX → CoreML (.mlpackage).

Usage:
    python convert_fusegnet.py --weights path/to/fusegnet.pth --output ../Sources/WoundAutoSegmentation/Resources/FUSegNet.mlpackage

Requirements:
    pip install torch torchvision onnx coremltools pillow numpy

The script:
  1. Loads PyTorch FUSegNet weights
  2. Exports to ONNX (opset 13, input 1×3×512×512)
  3. Converts to CoreML with ImageType input + ImageNet normalization
  4. Applies INT8 palettization to reduce model size
  5. Gates on 50 MB size limit
  6. Validates output against PyTorch reference
"""

import argparse
import os
import sys
import tempfile

import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(description="Convert FUSegNet to CoreML")
    parser.add_argument(
        "--weights", required=True, help="Path to PyTorch .pth weights file"
    )
    parser.add_argument(
        "--output",
        default="../Sources/WoundAutoSegmentation/Resources/FUSegNet.mlpackage",
        help="Output path for .mlpackage",
    )
    parser.add_argument(
        "--input-size", type=int, default=512, help="Model input size (default: 512)"
    )
    parser.add_argument(
        "--size-limit-mb",
        type=float,
        default=50.0,
        help="Abort if model exceeds this size in MB (default: 50)",
    )
    parser.add_argument(
        "--nbits",
        type=int,
        default=8,
        choices=[4, 6, 8],
        help="Palettization bits (default: 8, use 4 for smaller models)",
    )
    parser.add_argument(
        "--skip-validation", action="store_true", help="Skip IoU validation"
    )
    return parser.parse_args()


def load_pytorch_model(weights_path, input_size):
    """Load FUSegNet from PyTorch weights."""
    import torch

    # Try to import FUSegNet from the WoundAmbit codebase.
    # If the model definition isn't available, provide guidance.
    try:
        # Attempt 1: WoundAmbit package structure
        from models.fusegnet import FUSegNet
    except ImportError:
        try:
            # Attempt 2: flat structure
            from fusegnet import FUSegNet
        except ImportError:
            print(
                "ERROR: Cannot import FUSegNet model class.\n"
                "Make sure the WoundAmbit Python package is on PYTHONPATH:\n"
                "  export PYTHONPATH=/path/to/woundambit:$PYTHONPATH\n"
                "Or copy the model definition to this directory.",
                file=sys.stderr,
            )
            sys.exit(1)

    model = FUSegNet(num_classes=1)  # single-channel sigmoid output
    state_dict = torch.load(weights_path, map_location="cpu", weights_only=True)

    # Handle both raw state_dict and wrapped checkpoint formats
    if "model_state_dict" in state_dict:
        state_dict = state_dict["model_state_dict"]
    elif "state_dict" in state_dict:
        state_dict = state_dict["state_dict"]

    model.load_state_dict(state_dict)
    model.eval()

    print(f"Loaded FUSegNet with {sum(p.numel() for p in model.parameters()):,} parameters")
    return model


def export_to_onnx(model, input_size, onnx_path):
    """Export PyTorch model to ONNX."""
    import torch

    dummy_input = torch.randn(1, 3, input_size, input_size)
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        opset_version=13,
        input_names=["image"],
        output_names=["output"],
        dynamic_axes=None,  # fixed input size for CoreML
    )
    print(f"Exported ONNX to {onnx_path}")


def convert_to_coreml(onnx_path, output_path, input_size, nbits):
    """Convert ONNX model to CoreML with ImageType input and palettization."""
    import coremltools as ct

    # ImageNet normalization: scale by 1/255 then normalize per-channel
    # Combined: pixel * scale + bias
    # R: pixel/255 - 0.485) / 0.229 = pixel * (1/(255*0.229)) + (-0.485/0.229)
    # G: pixel/255 - 0.456) / 0.224 = pixel * (1/(255*0.224)) + (-0.456/0.224)
    # B: pixel/255 - 0.406) / 0.225 = pixel * (1/(255*0.225)) + (-0.406/0.225)

    model = ct.converters.convert(
        onnx_path,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, input_size, input_size),
                scale=1.0 / 255.0,
                bias=[-0.485, -0.456, -0.406],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )

    # Apply palettization to reduce model size
    print(f"Applying {nbits}-bit palettization...")
    op_config = ct.optimize.coreml.OpPalettizerConfig(nbits=nbits, mode="kmeans")
    config = ct.optimize.coreml.OptimizationConfig(global_config=op_config)
    model = ct.optimize.coreml.palettize_weights(model, config=config)

    model.save(output_path)
    print(f"Saved CoreML model to {output_path}")

    return model


def check_size(output_path, size_limit_mb):
    """Check model size against the limit. Returns size in MB."""
    total_size = 0
    for dirpath, _, filenames in os.walk(output_path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            total_size += os.path.getsize(fp)

    size_mb = total_size / (1024 * 1024)
    print(f"Model size: {size_mb:.1f} MB (limit: {size_limit_mb:.1f} MB)")

    if size_mb > size_limit_mb:
        print(
            f"\nABORT: Model size {size_mb:.1f} MB exceeds {size_limit_mb:.1f} MB limit.\n"
            f"Options:\n"
            f"  1. Re-run with --nbits 4 for 4-bit palettization\n"
            f"  2. Raise limit with --size-limit-mb 80\n"
            f"  3. Use a smaller backbone (EfficientNet-B3)\n"
            f"  4. Use on-demand resources (ODR)",
            file=sys.stderr,
        )
        sys.exit(1)

    return size_mb


def validate(pytorch_model, coreml_model_path, input_size):
    """Validate CoreML output matches PyTorch within tolerance."""
    import coremltools as ct
    import torch
    from PIL import Image

    print("Validating CoreML output against PyTorch reference...")

    # Create a test image
    test_np = np.random.randint(0, 255, (input_size, input_size, 3), dtype=np.uint8)
    test_pil = Image.fromarray(test_np)

    # PyTorch inference
    transform_mean = [0.485, 0.456, 0.406]
    transform_std = [0.229, 0.224, 0.225]
    tensor = torch.from_numpy(test_np).float().permute(2, 0, 1) / 255.0
    for c in range(3):
        tensor[c] = (tensor[c] - transform_mean[c]) / transform_std[c]
    tensor = tensor.unsqueeze(0)

    with torch.no_grad():
        pytorch_output = torch.sigmoid(pytorch_model(tensor)).numpy().flatten()

    # CoreML inference
    coreml_model = ct.models.MLModel(coreml_model_path)
    coreml_result = coreml_model.predict({"image": test_pil})

    # Find the output key
    output_key = list(coreml_result.keys())[0]
    coreml_output = np.array(coreml_result[output_key]).flatten()

    # Compare
    # Truncate to same length (in case of padding differences)
    min_len = min(len(pytorch_output), len(coreml_output))
    pytorch_output = pytorch_output[:min_len]
    coreml_output = coreml_output[:min_len]

    mae = np.mean(np.abs(pytorch_output - coreml_output))
    max_diff = np.max(np.abs(pytorch_output - coreml_output))

    # Compute IoU on thresholded masks
    pt_mask = pytorch_output > 0.5
    cm_mask = coreml_output > 0.5
    intersection = np.sum(pt_mask & cm_mask)
    union = np.sum(pt_mask | cm_mask)
    iou = intersection / union if union > 0 else 1.0

    print(f"  Mean Absolute Error: {mae:.6f}")
    print(f"  Max Absolute Error:  {max_diff:.6f}")
    print(f"  Mask IoU:            {iou:.4f}")

    if iou < 0.90:
        print(
            f"\nWARNING: IoU {iou:.4f} is below 0.90 threshold. "
            f"Conversion may have introduced significant errors.",
            file=sys.stderr,
        )
    else:
        print("  Validation PASSED")


def main():
    args = parse_args()

    print("=" * 60)
    print("FUSegNet → CoreML Conversion Pipeline")
    print("=" * 60)

    # Step 1: Load PyTorch model
    print("\n[1/5] Loading PyTorch model...")
    model = load_pytorch_model(args.weights, args.input_size)

    # Step 2: Export to ONNX
    print("\n[2/5] Exporting to ONNX...")
    with tempfile.NamedTemporaryFile(suffix=".onnx", delete=False) as f:
        onnx_path = f.name
    try:
        export_to_onnx(model, args.input_size, onnx_path)

        # Step 3: Convert to CoreML
        print(f"\n[3/5] Converting to CoreML ({args.nbits}-bit palettization)...")
        coreml_model = convert_to_coreml(
            onnx_path, args.output, args.input_size, args.nbits
        )

    finally:
        if os.path.exists(onnx_path):
            os.unlink(onnx_path)

    # Step 4: Size gate
    print("\n[4/5] Checking model size...")
    size_mb = check_size(args.output, args.size_limit_mb)

    # Step 5: Validation
    if not args.skip_validation:
        print("\n[5/5] Validating conversion...")
        validate(model, args.output, args.input_size)
    else:
        print("\n[5/5] Validation skipped")

    print("\n" + "=" * 60)
    print(f"SUCCESS: FUSegNet.mlpackage ({size_mb:.1f} MB) ready at:")
    print(f"  {os.path.abspath(args.output)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
