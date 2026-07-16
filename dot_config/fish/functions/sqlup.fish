function sqlup --description 'Levantar el SQL Server local (container Docker)'
    docker compose -f /home/<user>/mssql/docker-compose.yml up -d
end
