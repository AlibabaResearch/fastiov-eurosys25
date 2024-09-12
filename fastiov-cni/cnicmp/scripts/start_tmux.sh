#!/bin/bash

dokill=0
dokillstart=0
while getopts "kf" opt; do
  case ${opt} in
    k )
      dokill=1
      ;;
    f )
      dokillstart=1
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

SESSION_NAME="cnicmp"

start_tmux() {
  echo "starting tmux $SESSION_NAME..."
  tmux new-session -d -s $SESSION_NAME -n 'debug'
  tmux send-keys -t $SESSION_NAME:0 'cd /home/hdcni' C-m

  tmux new-window -t $SESSION_NAME -n 'test' -d
  tmux send-keys -t $SESSION_NAME:1 'cd /home/hdcni/cnicmp/scripts' C-m

  tmux new-window -t $SESSION_NAME -n 'log' -d
  tmux send-keys -t $SESSION_NAME:2 'cd /tmp/pod_test' C-m

  tmux new-window -t $SESSION_NAME -n 'cni' -d
  tmux send-keys -t $SESSION_NAME:3 'cd /etc/cni/net.d' C-m

  tmux new-window -t $SESSION_NAME -n 'ipu' -d
  tmux send-keys -t $SESSION_NAME:4 'cd /root/ipu/scripts' C-m

  tmux new-window -t $SESSION_NAME -n 'sync' -d
  tmux send-keys -t $SESSION_NAME:5 'cd /home/cni/cnicmp/scripts/ovs_test_scripts' C-m

  tmux attach -t $SESSION_NAME
  echo "starting tmux $SESSION_NAME ok"
}

kill_tmux() {
  echo "killing tmux $SESSION_NAME..."
  tmux kill-session -t $SESSION_NAME
  echo "killing tmux $SESSION_NAME ok"
}

if [ $dokill == 1 ]; then
  tmux has-session -t $SESSION_NAME 2>/dev/null
  if [ $? == 0 ]; then
    kill_tmux
  else
    echo "no tmux session named $SESSION_NAME found..."
  fi
fi

if [ $dokillstart == 1 ]; then
  tmux has-session -t $SESSION_NAME 2>/dev/null
  if [ $? == 0 ]; then
    kill_tmux
  else
    echo "no tmux session named $SESSION_NAME found..."
  fi
  start_tmux
fi

if [ $dokill == 0 ] && [ $dokillstart == 0 ]; then
  tmux has-session -t $SESSION_NAME 2>/dev/null
  if [ $? != 0 ]; then
    start_tmux
  else
    echo "tmux session named $SESSION_NAME already exists..."
  fi
fi
