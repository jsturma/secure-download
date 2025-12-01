var redis = require('redis');

var client = redis.createClient({
    host: "127.0.0.1",
    port: 6379
});

function jwt_to_session(r) {
    var sid = r.variables.cookie_sessionid;

    if (sid) {
        // Session exists → validate with Redis
        redis.exists(client, sid, function (err, res) {
            if (res == 1) {
                r.return(200);
            } else {
                r.return(401);
            }
        });
        return;
    }

    // No session cookie: attempt JWT authentication
    var user = r.variables.jwt_claim_sub;
    var dir  = r.variables.jwt_claim_aud;

    if (!user || !dir) {
        r.return(401);
        return;
    }

    // Create new session
    sid = crypto.randomBytes(16).toString('hex');

    redis.setex(client, sid, 28800, // TTL 8h
        JSON.stringify({ user: user, dir: dir }),
        function (err, res) {
            r.headersOut['Set-Cookie'] = "sessionid=" + sid + "; Path=/; Secure; HttpOnly";
            r.return(200);
        }
    );
}

export default { jwt_to_session };
