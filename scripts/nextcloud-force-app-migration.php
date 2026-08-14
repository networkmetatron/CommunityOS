<?php
declare(strict_types=1);
define('OC_CONSOLE', true);
require '/var/www/html/lib/base.php';

if ($argc < 4) {
	fwrite(STDERR, "Usage: php nextcloud-force-app-migration.php <app> <createVersion> <logicalTable>\n");
	exit(64);
}

$app = $argv[1];
$createVersion = $argv[2];
$logical = $argv[3];

try {
	$path = \OC_App::getAppPath($app);
	if (!$path) {
		fwrite(STDOUT, "FAIL app_path_missing app={$app}\n");
		exit(2);
	}
	\OC_App::loadApp($app);
	fwrite(STDOUT, "app_path={$path}\n");

	// MigrationService requires OC\DB\Connection, not the public IDBConnection adapter
	$adapter = \OC::$server->get(\OCP\IDBConnection::class);
	if ($adapter instanceof \OC\DB\ConnectionAdapter) {
		$conn = $adapter->getInner();
	} elseif ($adapter instanceof \OC\DB\Connection) {
		$conn = $adapter;
	} else {
		$conn = \OC::$server->get(\OC\DB\Connection::class);
	}

	$ms = new \OC\DB\MigrationService($app, $conn);

	$available = $ms->getAvailableVersions();
	fwrite(STDOUT, 'available_count=' . count($available) . "\n");
	fwrite(STDOUT, 'available=' . implode(',', $available) . "\n");
	fwrite(STDOUT, 'current_before=' . $ms->getMigration('current') . "\n");
	fwrite(STDOUT, 'migrated_before=' . implode(',', $ms->getMigratedVersions()) . "\n");

	if (count($available) === 0) {
		fwrite(STDOUT, "FAIL no_available_migrations\n");
		exit(3);
	}
	if (!in_array($createVersion, $available, true)) {
		fwrite(STDOUT, "FAIL create_version_not_available version={$createVersion}\n");
		exit(4);
	}

	fwrite(STDOUT, "executeStep {$createVersion}\n");
	$ms->executeStep($createVersion);
	fwrite(STDOUT, 'current_after_create=' . $ms->getMigration('current') . "\n");

	fwrite(STDOUT, "migrate latest\n");
	$ms->migrate('latest');
	fwrite(STDOUT, 'current_after_latest=' . $ms->getMigration('current') . "\n");
	fwrite(STDOUT, 'migrated_after=' . implode(',', $ms->getMigratedVersions()) . "\n");

	$sm = $conn->createSchemaManager();
	$prefix = method_exists($conn, 'getPrefix') ? $conn->getPrefix() : 'oc_';
	foreach ([$logical, $prefix . $logical, 'oc_' . $logical] as $name) {
		if ($sm->tablesExist([$name])) {
			fwrite(STDOUT, "schema_has_table={$name}\n");
			fwrite(STDOUT, "OK migration_applied\n");
			exit(0);
		}
	}
	fwrite(STDOUT, "FAIL table_not_in_schema logical={$logical} prefix={$prefix}\n");
	exit(5);
} catch (Throwable $e) {
	fwrite(STDOUT, 'EXCEPTION ' . get_class($e) . ': ' . $e->getMessage() . "\n");
	fwrite(STDOUT, $e->getFile() . ':' . $e->getLine() . "\n");
	fwrite(STDOUT, $e->getTraceAsString() . "\n");
	exit(1);
}
