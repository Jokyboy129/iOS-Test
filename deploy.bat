@echo off
echo 1. Opening repository...
gh repo edit --visibility public --accept-visibility-change-consequences

echo 2. Pushing code...
git push origin main

echo 3. Watching build...
gh run watch

echo 4. Downloading app...
gh run download -n ASMRHeartbeat-App

echo 5. Locking repository...
gh repo edit --visibility private --accept-visibility-change-consequences

echo Done! Your IPA is ready.