<?php
$host = getenv('MYSQL_HOST');
$port = getenv('MYSQL_PORT');
$dbname = getenv('MYSQL_DATABASE');
$username = getenv('MYSQL_USER');
$password = getenv('MYSQL_PASSWORD');

$pdo = new PDO("mysql:host=$host;port=$port;dbname=$dbname;charset=utf8", $username, $password, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
]);

$rows = $pdo->query('select version()')->fetchAll();
var_dump($rows);
