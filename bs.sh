#!/bin/bash

# 定义端口和阈值
PORT=6060
THRESHOLD=1024

# 无限循环检测
while true
do
    exceed_count=0

    # 检查6060端口的Recv-Q值，连续检查4次
    for i in {1..4}
    do
        recv_q=$(netstat -tnlp | grep ":$PORT " | awk '{print $2}')
        echo "当前端口 $PORT 的 Recv-Q 值为: $recv_q"

        # 检查Recv-Q值是否超过阈值
        if [[ "$recv_q" -gt "$THRESHOLD" ]]; then
            ((exceed_count++))
            curl -X POST "https://api.telegram.org/bot5759647032:AAHPXukEy2bbqvsYn5eok89zM5QjZkTCUMA/sendMessage" -d "chat_id=-1001880740874&text=桃源堵死啦！！！当前端口 $PORT 的 Recv-Q 值为: $recv_q"
        else
            echo "第一次检测Recv-Q值未超过 $THRESHOLD，重新开始检测。"
            break  # 如果第一次检测未超过1024，则跳出循环
        fi

        # 等待6秒后再次检查
        sleep 6
    done

    # 如果四次检查后Recv-Q值都超过了1024
    if [ "$exceed_count" -eq 4 ]; then
        echo "四次检测均超过阈值，尝试终止 BsStarter 进程。"

        # 使用jps命令查找BsStarter的PID
        pid=$(jps | grep 'BsStarter' | awk '{print $1}')
        if [ -n "$pid" ]; then
            echo "终止 PID 为 $pid 的 BsStarter 进程。"
            kill $pid  # 尝试杀死进程

            # 等待2秒并检查进程是否已被杀死
            sleep 2
            if ! ps -p $pid > /dev/null; then
                echo "BsStarter 进程已终止，正在重启服务。"
                sh /home/prod/tio-bs-server/tio-site-all/run.sh

                # 等待并检查服务是否重启成功
                sleep 2
                if jps | grep 'BsStarter' > /dev/null; then
                    echo "BsStarter 服务重启成功。"
                    curl -X POST "https://api.telegram.org/bot5759647032:AAHPXukEy2bbqvsYn5eok89zM5QjZkTCUMA/sendMessage" -d "chat_id=-1001880740874&text=桃源重启好啦！！！"
                else
                    echo "BsStarter 服务首次重启失败，尝试再次重启。"
                    sh /home/prod/tio-bs-server/tio-site-all/run.sh
                    sleep 2
                    if jps | grep 'BsStarter' > /dev/null; then
                        echo "BsStarter 服务第二次重启成功。"
                        curl -X POST "https://api.telegram.org/bot5759647032:AAHPXukEy2bbqvsYn5eok89zM5QjZkTCUMA/sendMessage" -d "chat_id=-1001880740874&text=桃源为啥重启了两次才好啊？？？"
                    else
                        echo "BsStarter 服务第二次重启失败。"
                        curl -X POST "https://api.telegram.org/bot5759647032:AAHPXukEy2bbqvsYn5eok89zM5QjZkTCUMA/sendMessage" -d "chat_id=-1001880740874&text=桃源挂逼了啊！！！救命啊！！！"
                    fi
                fi
            else
                echo "BsStarter 进程终止失败。"
            fi
        else
            echo "未找到 BsStarter 进程。"
        fi
    else
        echo "四次检测中 Recv-Q 值未持续超过阈值。"
    fi

    # 每次循环后休眠一段时间
    sleep 10
done
