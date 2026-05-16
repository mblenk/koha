use Modern::Perl;
use Koha::Installer::Output qw(say_success);

return {
    bug_number  => undef,
    description => "Add system preferences for vector/semantic search (VectorSearch)",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        for my $pref (
            [ 'VectorSearchEnabled',    '0'                      ],
            [ 'VectorSearchProvider',   ''                 ],
            [ 'VectorSearchModel',      ''       ],
            [ 'VectorSearchAPIKey',     ''                       ],
            [ 'VectorSearchDimensions', '768'                    ],
            )
        {
            $dbh->do(
                "INSERT IGNORE INTO systempreferences (variable, value) VALUES (?, ?)",
                undef, $pref->[0], $pref->[1]
            );
            say_success( $out, "Added system preference '$pref->[0]'" );
        }
    },
};
