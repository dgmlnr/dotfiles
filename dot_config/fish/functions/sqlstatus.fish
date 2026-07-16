function sqlstatus --description 'Estado del SQL Server local'
    docker compose -f /home/<user>/mssql/docker-compose.yml ps
end
