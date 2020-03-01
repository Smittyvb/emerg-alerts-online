# relies on serve NPM module being installed globally

echo "Starting dev server"
serve -s src/ & elm-live --no-server -- src/Main.elm --output=src/elm.js && fg
