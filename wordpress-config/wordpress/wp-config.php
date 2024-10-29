<?php
require_once __DIR__ . '/vendor/autoload.php';

use Aws\SecretsManager\SecretsManagerClient;
use Aws\Exception\AwsException;

function getSecretValue($secretName) {
    $client = new SecretsManagerClient([
        'version' => 'latest',
        'region' => 'eu-west-3',
    ]);

    try {
        $result = $client->getSecretValue(['SecretId' => $secretName]);
        return json_decode($result['SecretString'], true);
    } catch (AwsException $e) {
        error_log($e->getMessage());
        die('Erreur lors de la récupération des informations de la base de données.');
    }
}

$secret = getSecretValue('book');

// ** Database settings - Using AWS Secrets Manager ** //
/** The name of the database for WordPress */
define('DB_NAME', $secret['MYSQL_DATABASE']);
/** Database username */
define('DB_USER', $secret['MYSQL_USER']);
/** Database password */
define('DB_PASSWORD', $secret['MYSQL_PASSWORD']);
/** Database hostname */
define('DB_HOST', $secret['MYSQL_HOST']);
/** Database charset to use in creating database tables. */
define('DB_CHARSET', 'utf8');
/** The database collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');
/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/documentation/article/debugging-in-wordpress/
 */
define('WP_DEBUG', false);

// Additional security settings
define('FORCE_SSL_ADMIN', true);
define('FORCE_SSL_LOGIN', true);
define('WP_MEMORY_LIMIT', '256M');

/* Add any custom values between this line and the "stop editing" line. */

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if (!defined('ABSPATH')) {
    define('ABSPATH', dirname(__FILE__) . '/');
}

/** Sets up WordPress vars and included files. */
require_once(ABSPATH . 'wp-settings.php');
