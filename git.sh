#!/bin/bash
read -p "Enter the new commit: " COMMIT
git add .
git commit -m "$COMMIT"
git push origin main
