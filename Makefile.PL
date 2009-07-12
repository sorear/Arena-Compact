use inc::Module::Install;

name     'BIBOP';
all_from 'lib/BIBOP.pm';

ppport;

test_requires 'Test::More';
test_requires 'Test::Exception';
test_requires 'Task::Weaken';

WriteAll;

