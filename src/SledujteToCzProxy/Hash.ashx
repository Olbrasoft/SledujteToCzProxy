<%@ WebHandler Language="C#" Class="HashHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;

public class HashHandler : IHttpHandler
{
    // Shared with cr-web (SLEDUJTETO_PROXY_KEY). Rotate both sides together.
    private const string SharedSecret = "***REDACTED-PROXY-SECRET***";

    public void ProcessRequest(HttpContext ctx)
    {
        ctx.Response.ContentType = "application/json; charset=utf-8";
        ctx.Response.AddHeader("Access-Control-Allow-Origin", "*");
        ctx.Response.AddHeader("Cache-Control", "no-store");
        ctx.Response.TrySkipIisCustomErrors = true;

        string key = ctx.Request.QueryString["key"];
        if (string.IsNullOrEmpty(key) || key != SharedSecret)
        {
            ctx.Response.StatusCode = 403;
            ctx.Response.Write("{\"error\":\"forbidden\"}");
            return;
        }

        int id;
        if (!int.TryParse(ctx.Request.QueryString["id"], out id) || id <= 0)
        {
            ctx.Response.StatusCode = 400;
            ctx.Response.Write("{\"error\":\"id required\"}");
            return;
        }

        try
        {
            ServicePointManager.SecurityProtocol =
                SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

            var req = (HttpWebRequest)WebRequest.Create("https://www.sledujteto.cz/services/add-file-link");
            req.Method = "POST";
            req.ContentType = "application/json";
            req.Timeout = 15000;
            req.UserAgent = "Mozilla/5.0";

            byte[] body = Encoding.UTF8.GetBytes("{\"params\":{\"id\":" + id + "}}");
            req.ContentLength = body.Length;
            using (var s = req.GetRequestStream()) s.Write(body, 0, body.Length);

            string upstream;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            {
                upstream = sr.ReadToEnd();
            }

            // Parse video_url, extract CDN host (www / data{N} / unknown).
            string videoUrl = "";
            int vi = upstream.IndexOf("\"video_url\"");
            if (vi > 0)
            {
                int start = upstream.IndexOf('"', vi + 12) + 1;
                int end = upstream.IndexOf('"', start);
                if (end > start) videoUrl = upstream.Substring(start, end - start).Replace("\\/", "/");
            }

            string cdn = "unknown";
            bool streamable = false;
            if (videoUrl.StartsWith("https://www.sledujteto.cz/"))
            {
                cdn = "www";
                streamable = true;
            }
            else if (videoUrl.Contains(".sledujteto.cz/"))
            {
                int start = videoUrl.IndexOf("://") + 3;
                int end = videoUrl.IndexOf('.', start);
                cdn = end > start ? videoUrl.Substring(start, end - start) : "dataN";
                // data{N} is blocked from non-CZ ASNs; mark unstreamable so caller
                // can hide the copy or route differently (see cr#549).
                streamable = false;
            }

            var sb = new StringBuilder();
            sb.Append("{\"cdn\":\"").Append(cdn).Append("\",\"streamable\":").Append(streamable ? "true" : "false");
            sb.Append(",\"upstream\":").Append(upstream).Append("}");
            ctx.Response.Write(sb.ToString());
        }
        catch (Exception ex)
        {
            ctx.Response.StatusCode = 502;
            ctx.Response.Write("{\"error\":\"" +
                ex.Message.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"}");
        }
    }

    public bool IsReusable { get { return true; } }
}
