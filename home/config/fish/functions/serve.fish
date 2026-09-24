function serve --description 'Serve the current directory over HTTP'
    set -l port 8000
    if test (count $argv) -gt 0
        set port $argv[1]
    end

    python3 -m http.server $port
end
