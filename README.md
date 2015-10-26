# network-backup
Simple replacement for [RANCID](http://www.shrubbery.net/rancid/)

Since RANCID is a bit rancid, I've decided to make an alternative with git and ruby.

Name-suggestions are _welcome_, "network-backup" does lack a certain flair.

network-backup takes a json-configuration file and uses it to take backup of one or more cisco-ish network-devices.

* Login is assumed to be via preconfigured ssh-keys, preferably to a read-all/write-none user.
* Backed up data is currently the output of "show <something>" resulting in a <something> file
* Each backed up host gets its own git repository
* network-backup will create and maintain its own log-repository

TODO:
* make sure remote commands are properly escaped
* autodetect git-pushable repos and allow auto-push
