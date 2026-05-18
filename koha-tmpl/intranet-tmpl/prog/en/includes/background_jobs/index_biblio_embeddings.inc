[% SET report  = job.decoded_data.report %]
[% SET decoded = job.decoded_data %]

[% BLOCK report %]
    [% IF job.status == 'finished' %]
        [% IF report %]
            [% IF report.success == report.total %]
                <div class="alert alert-info">[% report.success | html %] bibliographic record(s) successfully indexed with embeddings.</div>
            [% ELSIF report.success == 0 %]
                <div class="alert alert-info">No records were indexed. All [% report.total | html %] record(s) were skipped.</div>
            [% ELSE %]
                <div class="alert alert-info">[% report.success | html %] / [% report.total | html %] record(s) indexed with embeddings. [% report.skipped | html %] skipped.</div>
            [% END %]
        [% ELSE %]
            <div class="alert alert-info">Job data could not be read, see the logs for details.</div>
        [% END %]
    [% ELSIF job.status == 'cancelled' %]
        <span>The job has been cancelled before it finished.</span>
    [% END %]
[% END %]

[% BLOCK detail %]
    [% IF decoded.record_ids %]
        <h3>Record IDs:</h3>
        <ul>
            [% FOREACH record_id IN decoded.record_ids %]
                <li><a href="/cgi-bin/koha/catalogue/detail.pl?biblionumber=[% record_id | uri %]">[% record_id | html %]</a></li>
            [% END %]
        </ul>
    [% END %]
[% END %]

[% BLOCK js %]
[% END %]
