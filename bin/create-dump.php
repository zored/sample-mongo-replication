#!/usr/bin/env php
<?php

const DUMP = './data/dump.js';
const USERS = 1000000;
const CHUNK_SIZE = 100;
echo 'Will create dump: ' . DUMP . PHP_EOL;
if (file_exists(DUMP)) {
	echo 'Dump already exists.' . PHP_EOL;
	return;
}

$file = fopen(DUMP, 'w');
fwrite($file, <<<JS
use test;
db.createCollection("user");
db.createIndex({name:"text", age:1});

JS
	);

for ($i=0; $i<USERS; /* ... */) {
	fwrite($file, "db.user.insertMany([");
	for ($j=0; $j<CHUNK_SIZE; $j++) {
		$name = bin2hex(random_bytes(10));
		$age = rand(20, 50);
		fwrite($file, '{name:"'.$name.'",age:'.$age.'},');
	}
	fwrite($file, "]);\n");
	$i += CHUNK_SIZE;

	if ($i % (USERS / 10) === 0) {
		echo round($i / USERS * 100) . '% ';
	}
}
echo PHP_EOL . 'Dump created.' . PHP_EOL;
