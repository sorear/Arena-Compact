use inc::Module::Install;

name     'Arena-Compact';
all_from 'lib/Arena/Compact.pm';

ppport;

test_requires 'Test::More';
test_requires 'Test::Exception';
test_requires 'Task::Weaken';

WriteAll;

