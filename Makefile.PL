use inc::Module::Install;

name     'Arena-BIBOP';
all_from 'lib/Arena/BIBOP.pm';

ppport;

test_requires 'Test::More';
test_requires 'Test::Exception';
test_requires 'Task::Weaken';

WriteAll;

