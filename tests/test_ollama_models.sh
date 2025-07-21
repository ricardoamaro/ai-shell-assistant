#!/bin/bash

reset;

for M in $(ollama list | grep -v NAME | awk '{print $1}' | sort); do
  echo "Model: $M"; OLLAMA_MODEL="$M" time -p ./tests/test_nl_shell.sh ollama | tail -n 20 ;
  echo ;
  sleep 30;
done | tee ollamatests-$(date +%Y%m%d_%H%M%S).log
