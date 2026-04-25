#!/bin/sh
set -e

XCCONFIG_PATH="${CI_PRIMARY_REPOSITORY_PATH}/Saman/Secrets.xcconfig"

echo "Generating Secrets.xcconfig from Xcode Cloud environment variables..."

cat > "$XCCONFIG_PATH" <<EOF
SUPABASE_URL = ${SUPABASE_URL}
SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY}
EOF

echo "Secrets.xcconfig written to ${XCCONFIG_PATH}"
