use Modern::Perl;
use Koha::Installer::Output qw(say_success say_info);

return {
    bug_number  => undef,
    description => "Add llm_providers table for chat-based search agent",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( TableExists('llm_providers') ) {
            $dbh->do(
                q{
                CREATE TABLE `llm_providers` (
                  `llm_provider_id`       int(11)      NOT NULL AUTO_INCREMENT COMMENT 'Primary key for the llm_providers table',
                  `name`                  varchar(255) NOT NULL COMMENT 'Admin-given label for this provider configuration',
                  `url`                   varchar(500) NOT NULL COMMENT 'Full endpoint URL for the chat completions API',
                  `model`                 varchar(255) NOT NULL COMMENT 'Model name substituted as {{model}} in the request body template',
                  `api_key`               text         DEFAULT NULL COMMENT 'Bearer token for authentication',
                  `auth_type`             enum('none','bearer') NOT NULL DEFAULT 'none' COMMENT 'Whether to send an Authorization header',
                  `request_body_template` text         NOT NULL COMMENT 'JSON body template with {{model}}, {{messages}}, {{system_prompt}}, and {{tool_definitions}} as sentinel values',
                  `response_key`          varchar(255) NOT NULL DEFAULT 'choices.0.message.content' COMMENT 'Dot-notation path to the reply text in the response',
                  `tool_definitions`      text         DEFAULT NULL COMMENT 'JSON array of tool definitions in provider-specific format; substituted via {{tool_definitions}} sentinel in the request body template',
                  `system_prompt`         text         DEFAULT NULL COMMENT 'System prompt injected at the start of every conversation',
                  `status`                enum('active','inactive') NOT NULL DEFAULT 'inactive' COMMENT 'Only one provider may be active at a time',
                  PRIMARY KEY (`llm_provider_id`),
                  UNIQUE KEY `name` (`name`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            }
            );
            say_success( $out, "Added new table 'llm_providers'" );
        }
    },
};
