function sqldown --description 'Bajar el SQL Server local (libera RAM; los datos persisten)'
    docker compose -f $HOME/mssql/docker-compose.yml stop
end
