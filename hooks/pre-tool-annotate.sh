input=$(cat)

command=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"//')
# append \\uFE0F to get emoji icon instead of unicode equivalent
#highlighted="${command//cd/\\u001b[34mcd\\u001b[0m\\u27A1 \\uD83D\\uDCC1}"
highlighted="${command//cd/\\u001b[34mcd\\u001b[0m\\u27A1 \\uD83D\\uDCC1}"
echo "{\"systemMessage\": \"$highlighted\"}"

exit 0