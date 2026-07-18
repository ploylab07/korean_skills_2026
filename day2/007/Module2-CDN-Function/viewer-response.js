async function handler(event) {
    var request = event.request;
    var response = event.response;
    var headers = request.headers || {};

    if (headers['x-sp-ab-assigned'] && headers['x-sp-ab-assigned'].value) {
        var v = headers['x-sp-ab-assigned'].value;
        if (!response.cookies) {
            response.cookies = {};
        }
        response.cookies['x-sp-ab'] = {
            value: v,
            attributes: 'Path=/; Max-Age=86400'
        };
    }
    return response;
}
