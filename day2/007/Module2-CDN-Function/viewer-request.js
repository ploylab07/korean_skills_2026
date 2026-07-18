import cf from 'cloudfront';
const kvsHandle = cf.kvs();

async function handler(event) {
    var request = event.request;
    var cookies = request.cookies || {};
    var assigned = null;
    var isNew = false;

    if (cookies['x-sp-ab'] && cookies['x-sp-ab'].value) {
        assigned = cookies['x-sp-ab'].value;
    } else {
        isNew = true;
        var weightStr = await kvsHandle.get('weight');
        var weight = parseFloat(weightStr);
        var rand = Math.random();
        if (rand < weight) {
            assigned = 'b';
        } else {
            assigned = 'a';
        }
    }

    var versionKey = (assigned === 'b') ? 'version_b' : 'version_a';
    var uri = await kvsHandle.get(versionKey);
    request.uri = uri;

    if (!request.headers) {
        request.headers = {};
    }
    if (isNew) {
        request.headers['x-sp-ab-assigned'] = { value: assigned };
    }

    return request;
}
