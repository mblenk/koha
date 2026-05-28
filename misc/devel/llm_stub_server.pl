#!/usr/bin/env perl

# llm_stub_server.pl — OpenAI-compatible LLM stub for KTD development
#
# Intercepts /v1/chat/completions requests from Koha's LLMClient and answers
# them using the `claude -p` CLI, which shares this session's auth so no
# separate Anthropic API key is needed.
#
# Usage:
#     perl misc/devel/llm_stub_server.pl [--port PORT]
#
# Then set the active llm_providers row URL to:
#     http://host.docker.internal:<PORT>/v1/chat/completions
#
# The existing Ollama request_body_template and response_key work unchanged:
#     template:     {"model":"{{model}}","messages":"{{messages}}","stream":false}
#     response_key: choices.0.message.content

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use HTTP::Daemon;
use HTTP::Response;
use HTTP::Status qw(:constants);
use JSON::PP     qw(decode_json encode_json);
use IPC::Open3;
use Symbol qw(gensym);

my $port = 11435;
GetOptions( 'port=i' => \$port ) or die "Usage: $0 [--port PORT]\n";

my $daemon = HTTP::Daemon->new(
    LocalPort => $port,
    ReuseAddr => 1,
) or die "[stub] Cannot listen on port $port: $!\n";

print "[stub] Listening on http://0.0.0.0:$port/v1/chat/completions\n";
print "[stub] KTD provider URL: http://host.docker.internal:$port/v1/chat/completions\n";

while ( my $conn = $daemon->accept ) {
    while ( my $req = $conn->get_request ) {
        handle_request( $conn, $req );
    }
    $conn->close;
}

sub handle_request {
    my ( $conn, $req ) = @_;

    unless ( $req->method eq 'POST' && $req->uri->path eq '/v1/chat/completions' ) {
        $conn->send_response( HTTP::Response->new(HTTP_NOT_FOUND) );
        return;
    }

    my $body = $req->content;
    # printf "[stub] raw body (%d bytes): %s\n", length($body), substr( $body, 0, 200 );

    my ( $response_body, $log_reply );
    eval {
        my $data        = decode_json($body);
        my $messages    = $data->{messages} // die "No messages in request\n";
        my $has_tools   = @{ $data->{tools} // [] } > 0;
        my $has_results = grep { ( $_->{role} // '' ) eq 'tool' } @$messages;

        if ( $has_tools && !$has_results ) {
            # Phase 1: request carries tool definitions but no tool results yet —
            # ask Claude to pick the right tool and arguments, then wrap the result
            # in the OpenAI tool_calls response shape.
            my $tool_json = ask_claude( build_tool_selection_prompt( $messages, $data->{tools} ) );
            my $tool_call = eval { decode_json($tool_json) };
            warn "**************************";
            warn "STRATEGY: " . $tool_call->{arguments}->{strategy};
            warn "KEYWORD: " . $tool_call->{arguments}->{keyword_query};
            warn "SEMANTIC: " . $tool_call->{arguments}->{semantic_query};
            if ( !$tool_call || ref $tool_call ne 'HASH' ) {
                warn "[stub] Could not parse tool selection JSON ('$tool_json'), using fallback\n";
                my $user_query = '';
                for my $msg ( reverse @$messages ) {
                    if ( ( $msg->{role} // '' ) eq 'user' ) {
                        $user_query = $msg->{content} // '';
                        last;
                    }
                }
                $tool_call = {
                    name      => $data->{tools}[0]{function}{name} // 'search_catalogue',
                    arguments => { query => $user_query, strategy => 'hybrid' },
                };
            }
            my $tool_name = $tool_call->{name};
            my $arguments = encode_json( $tool_call->{arguments} );
            $log_reply    = "[tool_call] $tool_name(" . substr( $arguments, 0, 80 ) . ")";
            $response_body = encode_json( {
                id      => 'stub-0',
                object  => 'chat.completion',
                model   => 'claude-stub',
                choices => [ {
                    index   => 0,
                    message => {
                        role       => 'assistant',
                        content    => undef,
                        tool_calls => [ {
                            id       => 'call_0',
                            type     => 'function',
                            function => { name => $tool_name, arguments => $arguments },
                        } ],
                    },
                    finish_reason => 'tool_calls',
                } ],
                usage => { prompt_tokens => 0, completion_tokens => 0, total_tokens => 0 },
            } );
        } else {
            # Phase 2: tool results are present (or no tools used) — generate final
            # text reply via the claude CLI.
            my $prompt = build_prompt($messages);
            # printf "[stub] prompt (%d chars):\n%s\n", length($prompt), substr( $prompt, 0, 200 );
            my $reply  = ask_claude($prompt);
            $log_reply = $reply;
            $response_body = encode_json( {
                id      => 'stub-0',
                object  => 'chat.completion',
                model   => 'claude-stub',
                choices => [ {
                    index         => 0,
                    message       => { role => 'assistant', content => $reply },
                    finish_reason => 'stop',
                } ],
                usage => { prompt_tokens => 0, completion_tokens => 0, total_tokens => 0 },
            } );
        }
    };
    if ($@) {
        my $err = "[stub error] $@";
        chomp $err;
        warn "[stub] ERROR: $@";
        $log_reply     = $err;
        $response_body = encode_json( {
            id      => 'stub-0',
            object  => 'chat.completion',
            model   => 'claude-stub',
            choices => [ {
                index         => 0,
                message       => { role => 'assistant', content => $err },
                finish_reason => 'stop',
            } ],
            usage => { prompt_tokens => 0, completion_tokens => 0, total_tokens => 0 },
        } );
    }

    # printf "[stub] reply: %s\n", substr( $log_reply, 0, 120 );

    my $response = HTTP::Response->new(HTTP_OK);
    $response->content_type('application/json');
    $response->content($response_body);
    $conn->send_response($response);
}

sub build_tool_selection_prompt {
    my ( $messages, $tools ) = @_;

    my @context_parts;
    for my $msg (@$messages) {
        my $role = $msg->{role} // 'user';
        next unless $role eq 'system' || $role eq 'user';
        my $label = $role eq 'system' ? 'System' : 'User';
        push @context_parts, "$label: " . ( $msg->{content} // '' );
    }

    my @tool_parts;
    for my $tool ( @{ $tools // [] } ) {
        my $fn   = $tool->{function} // {};
        my $name = $fn->{name} // 'unknown';
        my $desc = $fn->{description} // '';
        my $params = $fn->{parameters}{properties} // {};
        my $required = $fn->{parameters}{required} // [];

        my @param_lines;
        for my $pname ( sort keys %$params ) {
            my $p    = $params->{$pname};
            my $type = $p->{type} // 'string';
            my $pdesc = $p->{description} // '';
            my $enum = $p->{enum} ? join( ' | ', map { qq("$_") } @{ $p->{enum} } ) : '';
            my $req  = ( grep { $_ eq $pname } @$required ) ? 'required' : 'optional';
            my $line = "    $pname ($type, $req): $pdesc";
            $line .= " — $enum" if $enum;
            push @param_lines, $line;
        }

        my $arg_example = join( ', ', map { qq("$_": "...") } @$required );
        push @tool_parts,
            "- $name\n"
            . "  Description: $desc\n"
            . "  Parameters:\n"
            . join( "\n", @param_lines ) . "\n"
            . "  Example response: {\"name\": \"$name\", \"arguments\": {$arg_example}}";
    }

    return join( "\n\n", @context_parts )
        . "\n\n"
        . "Choose a tool to call from the list below and respond with ONLY a JSON object.\n"
        . "No explanation, no markdown — raw JSON only.\n\n"
        . "Tools:\n"
        . join( "\n\n", @tool_parts )
        . "\n\nResponse format: {\"name\": \"<tool_name>\", \"arguments\": {<key>: <value>, ...}}";
}

sub build_prompt {
    my ($messages) = @_;
    my @parts;
    for my $msg (@$messages) {
        my $role    = $msg->{role}    // 'user';
        my $content = $msg->{content} // '';
        my $label =
              $role eq 'system'    ? 'System'
            : $role eq 'assistant' ? 'Assistant'
            : $role eq 'tool'      ? 'Tool result'
            :                        'User';
        push @parts, "$label: $content";
    }
    return join "\n\n", @parts;
}

sub ask_claude {
    my ($prompt) = @_;
    my $err = gensym;
    my $pid = open3( my $in, my $out, $err, 'claude', '-p', $prompt );
    close $in;
    my $reply  = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid $pid, 0;
    my $exit = $? >> 8;
    die "claude exited $exit: $stderr\n" if $exit != 0;
    $reply =~ s/\s+\z//;
    return $reply;
}
