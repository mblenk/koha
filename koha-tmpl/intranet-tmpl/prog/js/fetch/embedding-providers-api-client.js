export class EmbeddingProvidersAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/embedding_providers",
        });
    }

    get embedding_providers() {
        return {
            create: embedding_provider =>
                this.httpClient.post({
                    endpoint: "",
                    body: embedding_provider,
                }),
            delete: id =>
                this.httpClient.delete({
                    endpoint: "/" + id,
                }),
            update: (embedding_provider, id) =>
                this.httpClient.put({
                    endpoint: "/" + id,
                    body: embedding_provider,
                }),
            get: id =>
                this.httpClient.get({
                    endpoint: "/" + id,
                }),
            getAll: (query, params) =>
                this.httpClient.getAll({
                    endpoint: "/",
                    query,
                    params,
                    headers: {},
                }),
            count: (query = {}) =>
                this.httpClient.count({
                    endpoint:
                        "?" +
                        new URLSearchParams({
                            _page: 1,
                            _per_page: 1,
                            ...(query && { q: JSON.stringify(query) }),
                        }),
                }),
        };
    }
}

export default EmbeddingProvidersAPIClient;
