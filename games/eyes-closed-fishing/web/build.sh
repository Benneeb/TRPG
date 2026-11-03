#!/bin/sh
# game.html(본문)을 감싸서 브라우저에서 바로 열 수 있는 index.html을 만듭니다.
cd "$(dirname "$0")"
{
  printf '<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
  sed -n '1,/<\/style>/p' game.html
  printf '</head>\n<body>\n'
  sed '1,/<\/style>/d' game.html
  printf '</body>\n</html>\n'
} > index.html
