use inc::Module::Install;

name     'BIBOP';
all_from 'lib//BIBOP.pm';

build_requires 'Test::More';

WriteAll;

