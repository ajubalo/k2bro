Implement util.py to be run with uv with embedded dependencies.DeprecationWarning

It accepts multiple commands, you run with `uv run util.py` followed by a command and args.

Reads token from .token if it exixts

If the token is missing read the .env
and perform the login in 2 steps,
using https://keep2share.github.io/api/#resources:/login:post

first request with username and password,
show the challenge url, then read the answer
then try again providing the challenge
and the returned response to get the token.

# link <ulr>

expect url in format https://k2s.cc/file/94767fbd8249a/MonstersOfC0ck_e045_mckloey-1080p.rar

generate the url using the `.token`  and https://keep2share.github.io/api/#resources:/getUrl:post

# vlc <url>

generate the link then open it in vlc
print the link


# login

execute the antentication flow
save the tokene in $HOME/Library/Containers/com.example.flutte/Data/Documents/.token

# info <url>

execute the get info of the file without autentication
return the values to determine if the file is available

