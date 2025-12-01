# 1. OpenResty (nginx + lua)
# https://openresty.org/en/installation.html (résumé rapide)
sudo apt-get update
sudo apt-get install -y curl gnupg2 software-properties-common
# ajouter repo openresty
curl -O https://openresty.org/package/pubkey.gpg
sudo apt-key add pubkey.gpg
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update
sudo apt-get install -y openresty

# 2. Redis
sudo apt-get install -y redis-server
sudo systemctl enable --now redis

# 3. LuaRocks et paquets Lua utiles
sudo apt-get install -y luarocks
sudo luarocks install lua-resty-http
sudo luarocks install lua-resty-jwt
sudo luarocks install lua-resty-redis
sudo luarocks install lua-resty-string
sudo luarocks install lua-resty-random
