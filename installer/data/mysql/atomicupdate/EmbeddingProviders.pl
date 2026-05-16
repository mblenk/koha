use Modern::Perl;
use Koha::Installer::Output qw(say_success say_info);

return {
    bug_number  => undef,
    description => "Add embedding_providers table and migrate VectorSearch configuration",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( TableExists('embedding_providers') ) {
            $dbh->do(
                q{
                CREATE TABLE `embedding_providers` (
                  `embedding_provider_id` int(11)      NOT NULL AUTO_INCREMENT COMMENT 'Primary key for the embedding_providers table',
                  `name`                  varchar(255) NOT NULL COMMENT 'Admin-given label for this provider configuration',
                  `url`                   varchar(500) NOT NULL COMMENT 'Full endpoint URL for the embedding API',
                  `model`                 varchar(255) NOT NULL COMMENT 'Model name substituted as {{model}} in the request body template',
                  `api_key`               text         DEFAULT NULL COMMENT 'Bearer token for authentication',
                  `auth_type`             enum('none','bearer') NOT NULL DEFAULT 'none' COMMENT 'Whether to send an Authorization header',
                  `request_body_template` text         NOT NULL COMMENT 'JSON body template with {{text}} and {{model}} as sentinel values',
                  `response_key`          varchar(255) NOT NULL DEFAULT 'data.0.embedding' COMMENT 'Dot-notation path to the embedding array in the response',
                  `dimensions`            int(11)      NOT NULL DEFAULT 768 COMMENT 'Vector dimensionality',
                  `status`                enum('active','inactive') NOT NULL DEFAULT 'inactive' COMMENT 'Only one provider may be active at a time',
                  PRIMARY KEY (`embedding_provider_id`),
                  UNIQUE KEY `name` (`name`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            }
            );
            say_success( $out, "Added new table 'embedding_providers'" );
        }
    },
};
