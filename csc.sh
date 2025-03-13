#!/bin/bash
# csc script: Save and process Claude conversations
# Configuration
LOG_DIR="$HOME/claude_log/"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAW_LOG="$LOG_DIR/claude_raw_$TIMESTAMP.log"
PROCESSED_LOG="$LOG_DIR/claude_conversation_$TIMESTAMP.txt"

# Create directory if it doesn't exist
mkdir -p "$LOG_DIR"
echo "Starting Claude conversation logging. Enter 'exit' to quit."
echo "Raw log: $RAW_LOG"
echo "Processed conversation: $PROCESSED_LOG"

# Record conversation using script command
script -q "$RAW_LOG" -c "claude $*" || {
  echo "Error occurred while running Claude!" >&2
  exit 1
}

# Post-process the log
echo "Processing conversation content..."
# Remove ANSI escape codes
sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' "$RAW_LOG" > "${RAW_LOG}.clean"

# Extract conversation content and number with awk
awk '
  BEGIN { 
    user=""; claude=""; in_user=0; in_claude=0; 
    counter=0;  # Conversation counter
    MAXHISTORY=10; 
    for (i=0; i<MAXHISTORY; i++) history[i]=""; 
  }
  
  # Filter out unnecessary UI and tool usage patterns
  /! for bash|· \/ for commands|\\\⏎ for newline|Search\(pattern:|Read\(file_path:|Bash\(|List\(|View\(|Edit\(|Update\(|mode[[:space:]]+newline/ { next; }
  
  # Function to check for duplicates
  function is_duplicate(line) {
    for (i=0; i<MAXHISTORY; i++) if (history[i] == line) return 1;
    return 0;
  }
  
  # Function to update history
  function add_to_history(line) {
    for (i=MAXHISTORY-1; i>0; i--) history[i]=history[i-1];
    history[0]=line;
  }
  
  # Skip duplicate lines
  { if (is_duplicate($0)) next; add_to_history($0); }
  
  # User input (starting with >)
  /^[[:space:]]*>/ { 
    if (in_claude && claude != "") {
      counter++;
      sub(/\n+$/, "", claude);
      print counter ". Claude: " claude "\n";  # Add newline
      claude = "";
    }
    in_claude = 0; in_user = 1;
    sub(/^[[:space:]]*>/, "");
    gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    if ($0 != "") user = $0;
    next;
  }
  
  # Claude response (starting with ●)
  /●/ { 
    if (in_user && user != "") {
      counter++;
      sub(/\n+$/, "", user);
      print counter ". User: " user "\n";  # Add newline
      user = "";
    }
    in_user = 0; in_claude = 1;
    sub(/^[^●]*●/, "");
    gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    if ($0 != "") claude = $0;
    next;
  }
  
  # Handle continuous lines
  /^[[:space:]]/ && NF > 0 && !/\+[0-9]+ lines/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    if (in_user && $0 != "") user = user " " $0;
    else if (in_claude && $0 != "") claude = claude " " $0;  # Including Bash
    next;
  }
  
  # Ignore empty lines
  NF == 0 { next; }
  
  # Final output
  END {
    if (in_user && user != "") {
      counter++;
      sub(/\n+$/, "", user);
      print counter ". User: " user "\n";
    }
    if (in_claude && claude != "") {
      counter++;
      sub(/\n+$/, "", claude);
      print counter ". Claude: " claude "\n";
    }
  }
' "${RAW_LOG}.clean" > "$PROCESSED_LOG"

# Delete temporary file
rm "${RAW_LOG}.clean"
echo "Conversation has been processed and saved: $PROCESSED_LOG"
cat "$PROCESSED_LOG"  # View results