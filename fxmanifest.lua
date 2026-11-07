fx_version 'cerulean'
game 'gta5'

name 'movie-player'
description 'YouTube/Twitch video player with DUI, shareable with nearby players'
author 'Tani'
version '3.0.0'

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
