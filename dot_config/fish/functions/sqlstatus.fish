function sqlstatus --description 'Estado del SQL Server local'
    docker compose -f $HOME/mssql/docker-compose.yml ps
end
