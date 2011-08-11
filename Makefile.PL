use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Heart::Domain::API',
    AUTHOR              => q{Brad Haywood <brad@geeksware.net>},
    VERSION_FROM        => 'lib/Heart/Domain/API.pm',
    ABSTRACT_FROM       => 'lib/Heart/Domain/API.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'IO::Socket::SSL' => 0,
        'File::Basename' => 0,
        'Data::Dumper'  => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Heart-Domain-API-*' },
);
