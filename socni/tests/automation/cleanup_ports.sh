sudo lsof -i | grep aranya
sudo lsof -i :4321 | grep LISTEN | awk '{print $2}' | xargs sudo kill -9