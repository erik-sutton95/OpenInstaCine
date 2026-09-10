#!/bin/zsh
LUNA_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
/usr/bin/python3 "$LUNA_PROJECT_DIR/tools/luna_mac.py"
LUNA_RESULT=$?
if [ "$LUNA_RESULT" -ne 0 ]; then
  print "Preview stopped with an error. See the output above."
  read -r "?Press Return to close."
fi
exit "$LUNA_RESULT"
