

## AC-HAXE

The *bare beginnings* of an implementation of Emacs auto-complete using the Haxe completion server. Requires `auto-complete` and `projectile` Emacs packages and Haxe 3.4.0-rc1 or above. Don't even bother with this extension unless you are prepared to alter hard-coded settings in the elisp source (and to put up with numerous bugs).

This package uses Haxe's new `--wait stdio` and `-D display-stdio` to launch the Haxe server automatically from within Emacs and to perform completion by piping the current file's bytes directly to the process. This obviates the need to launch the server manually and does not force saving the file's current modifications to disk.

This package was started using [hxc-complete.el](https://github.com/cloudshift/hx-emacs/blob/master/hxc-complete.el) as a guide and inspiration.
