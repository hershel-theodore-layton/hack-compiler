#!/usr/bin/env hhvm
/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\CLI;

use namespace HH;
use namespace HH\Lib\Str;
use namespace HTL\HackCompiler;
use type InvalidArgumentException;
use function array_reduce, dirname;
use const PHP_EOL;

/**
 * @license MIT-0
 * @copyright Hershel Theodore Layton, 2025
 *
 * This function is licensed under MIT-0. It may be copied freely without
 * restriction. Not even this docblock need to be preserved.
 */
function initialize_autoloader()[defaults]: void {
  if (!Str\ends_with(__FILE__, '.hack') || HH\autoload_is_native()) {
    return;
  }

  $invoke_autoloader = () ==> {
    try {
      // Abuse the poor typing of array_reduce to invoke a dynamic callable without hh_client noticing
      array_reduce(
        vec[null],
        HH\dynamic_fun('Facebook\AutoloadMap\initialize'),
      );
    } catch (InvalidArgumentException $e) {
      echo $e->getMessage();
      exit(1);
    }
  };

  $file = '/vendor/autoload.hack';

  $dir = __DIR__;
  $last_dir = $dir;
  // Dependencies are not available until we have found the autoloader.
  $to_mixed = (mixed $value)[]: mixed ==> $value;

  do {
    if (HH\could_include($dir.$file)) {
      require_once $dir.$file;
      $invoke_autoloader();
      return;
    }

    $last_dir = $dir;
    $dir = dirname($dir) |> $to_mixed($$) as string;
  } while ($last_dir !== $dir);

  echo
    'Could not find vendor/autoload.hack and native autoloading was not enabled. '.
    'You can resolve this by enabling `hhvm.autoload.enabled = true` in your '.
    'INI settings and setting a `hhvm.autoload.db.path`. If you cannot use '.
    'native autoloading, invoke vendor/bin/hh-autoload and try again.'.
    PHP_EOL;
  exit(1);
}

<<__EntryPoint>>
async function main_async()[defaults]: Awaitable<void> {
  initialize_autoloader();
  await HackCompiler\_Private\cli_async();
}
