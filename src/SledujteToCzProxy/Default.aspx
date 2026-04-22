<%@ Page Language="C#" ResponseEncoding="utf-8" ContentType="text/html; charset=utf-8" %>
<!DOCTYPE html>
<html lang="cs">
<head>
    <meta charset="utf-8">
    <title>SledujteToCzProxy</title>
    <style>
        body { background: #111; color: #eee; font-family: system-ui, sans-serif; padding: 1rem; max-width: 720px; margin: auto; }
        h1 { color: #8cf; font-size: 1.3rem; margin: 0 0 .6rem; }
        code { background: #222; padding: 0 .3em; border-radius: 2px; }
        .ok { color: #0f0; }
        table { border-collapse: collapse; margin-top: .6rem; }
        td, th { border: 1px solid #333; padding: .3rem .6rem; text-align: left; font-size: .9rem; }
        th { background: #222; }
    </style>
</head>
<body>
    <h1>SledujteToCzProxy</h1>
    <p>CZ-IP proxy for <a href="https://ceskarepublika.wiki" style="color:#8cf;">ceskarepublika.wiki</a> — sledujteto.cz source.
       Endpoints below require <code>?key=&lt;shared-secret&gt;</code>.</p>
    <table>
        <tr><th>Endpoint</th><th>Purpose</th></tr>
        <tr><td><code>Hash.ashx?id=&lt;file_id&gt;&amp;key=…</code></td><td>POST /services/add-file-link upstream, returns <code>{cdn, streamable, upstream}</code></td></tr>
        <tr><td><code>Search.ashx?q=&lt;query&gt;&amp;key=…</code></td><td>GET /api/web/videos upstream, cached 10 min</td></tr>
    </table>
    <p>Server: <%= Request.ServerVariables["SERVER_NAME"] %> · Time: <%= DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") %> · Status: <span class="ok">Running</span></p>
</body>
</html>
