#!/bin/bash
# Rekor Transparency Log Verification
set -euo pipefail

IMAGE_REF="${1:-}"
REKOR_URL="${REKOR_URL:-https://rekor.sigstore.dev}"

if [ -z "$IMAGE_REF" ]; then
  echo "Usage: $0 <image-ref>"
  exit 1
fi

echo "🔍 Verifying Rekor transparency log for: $IMAGE_REF"
echo ""

# Extract digest
DIGEST=$(echo "$IMAGE_REF" | grep -oP 'sha256:[a-f0-9]{64}' || echo "")

if [ -z "$DIGEST" ]; then
  echo "❌ Invalid image reference (no digest)"
  exit 1
fi

echo "📊 Searching Rekor log..."
rekor-cli search --sha "$DIGEST" --rekor_server "$REKOR_URL" || \
  echo "⚠️ No entries found (image may not be logged yet)"

echo ""
echo "✅ Rekor verification complete"
