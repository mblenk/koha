[%#
    FIXME: This is a native-HTML fallback for the <semantic-search-modal> Vue island.
    It exists because islands.esm.js is only loaded on pages that use main-container.inc,
    so the custom element is never hydrated on pages that do not use that
    wrapper. Once main-container.inc coverage is extended to all staff pages (or islands
    loading is moved to an earlier include that is present on every page), this file should
    be replaced by:
        <semantic-search-modal search-url="/cgi-bin/koha/catalogue/search.pl"></semantic-search-modal>
    and this include can be deleted.
%]
[% USE raw %]
[% USE Koha %]
[% IF Koha.Preference('VectorSearchEnabled') %]
    <div id="semanticSearchModal" class="modal fade" tabindex="-1" aria-labelledby="semanticSearchModalLabel" aria-hidden="true">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 id="semanticSearchModalLabel" class="modal-title">Semantic search</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <label for="semanticSearchQuery" class="form-label"> Describe what you're looking for in plain language </label>
                    <textarea id="semanticSearchQuery" class="form-control" rows="3" style="margin-top: 1em"></textarea>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                    <button type="button" class="btn btn-primary" id="semanticSearchSubmit">Search</button>
                </div>
            </div>
        </div>
    </div>
    <script nonce="[% Koha.CSPNonce | $raw %]">
        (function () {
            var modal = document.getElementById("semanticSearchModal");
            modal.addEventListener("shown.bs.modal", function () {
                document.getElementById("semanticSearchQuery").focus();
            });
            modal.addEventListener("hidden.bs.modal", function () {
                document.getElementById("semanticSearchQuery").value = "";
            });
            function doSemanticSearch() {
                var q = document.getElementById("semanticSearchQuery").value.trim();
                if (!q) return;
                window.location.href = "/cgi-bin/koha/catalogue/search.pl?q=" + encodeURIComponent(q) + "&semantic=1";
            }
            document.getElementById("semanticSearchSubmit").addEventListener("click", doSemanticSearch);
            document.getElementById("semanticSearchQuery").addEventListener("keyup", function (e) {
                if (e.key === "Enter") doSemanticSearch();
            });
        })();
    </script>
[% END %]
