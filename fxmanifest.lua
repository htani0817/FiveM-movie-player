fx_version 'cerulean'
game 'gta5'

name 'tani-watch'
description 'YouTube/Twitch Video Player with DUI and screen sharing'
author 'Tani'
version '2.3.0'

shared_scripts {
    'config.lua',
    'shared.lua'
}

client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/player.html',
    'html/fonts/Outfit-latin.woff2',
    'html/fonts/OFL.txt'
}
