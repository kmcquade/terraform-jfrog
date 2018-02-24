## add ssl entries when https has been set in config
ssl_certificate /etc/nginx/ssl/${artifactory_url}.crt;
ssl_certificate_key /etc/nginx/ssl/${artifactory_url}.key;
ssl_session_cache shared:SSL:1m;
ssl_protocols  TLSv1.1 TLSv1.2;
ssl_ciphers  HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers   on;

server {
    listen 80;
    server_name ${artifactory_url};
    return 301 https://$host$request_uri;
}

## server configuration
server {
    listen 443 ssl;

    server_name ${artifactory_url};
    if ($http_x_forwarded_proto = '') {
        set $http_x_forwarded_proto  $scheme;
    }
    ## Application specific logs
    ## access_log /var/log/nginx/${artifactory_url}-access.log timing;
    ## error_log /var/log/nginx/${artifactory_url}-error.log;
    rewrite ^/$ /artifactory/webapp/ redirect;
    rewrite ^/artifactory/?(/webapp)?$ /artifactory/webapp/ redirect;
    chunked_transfer_encoding on;
    client_max_body_size 0;
    location / {
    proxy_read_timeout  900;
    proxy_pass_header   Server;
    proxy_cookie_path   ~*^/.* /;
    if ( $request_uri ~ ^/artifactory/(.*)$ ) {
        proxy_pass          http://${artifactory_url}:8081/artifactory/$1;
    }
    proxy_pass          http://${artifactory_url}:8081/artifactory/;
    proxy_set_header    X-Artifactory-Override-Base-Url $http_x_forwarded_proto://$host/artifactory;
    proxy_set_header    X-Forwarded-Port  $server_port;
    proxy_set_header    X-Forwarded-Proto $http_x_forwarded_proto;
    proxy_set_header    Host              $http_host;
    proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_redirect      http:// https://;
    proxy_request_buffering off;
    proxy_http_version 1.1;
    }
}
