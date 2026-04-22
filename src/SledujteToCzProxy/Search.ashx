<%@ WebHandler Language="C#" Class="SearchHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Web.Caching;

public class SearchHandler : IHttpHandler
{
    private const string SharedSecret = "***REDACTED-PROXY-SECRET***";

    public void ProcessRequest(HttpContext ctx)
    {
        ctx.Response.ContentType = "application/json; charset=utf-8";
        ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*");
        ctx.Response.TrySkipIisCustomErrors = true;

        string key = ctx.Request.QueryString["key"];
        if (string.IsNullOrEmpty(key) || key != SharedSecret)
        {
            ctx.Response.StatusCode = 403;
            ctx.Response.Write("{\"error\":\"forbidden\"}");
            return;
        }

        string q = ctx.Request.QueryString["q"];
        if (string.IsNullOrEmpty(q))
        {
            ctx.Response.StatusCode = 400;
            ctx.Response.Write("{\"error\":\"q required\"}");
            return;
        }

        // Optional page + limit — defaults match prototype.
        string page = ctx.Request.QueryString["page"];
        string limit = ctx.Request.QueryString["limit"];
        if (string.IsNullOrEmpty(page)) page = "1";
        if (string.IsNullOrEmpty(limit)) limit = "50";

        string cacheKey = "search_" + q.ToLowerInvariant() + "_p" + page + "_l" + limit;
        string cached = ctx.Cache[cacheKey] as string;
        if (cached != null)
        {
            ctx.Response.Write(cached);
            return;
        }

        try
        {
            ServicePointManager.SecurityProtocol =
                SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

            string url = "https://www.sledujteto.cz/api/web/videos"
                + "?query=" + HttpUtility.UrlEncode(q)
                + "&limit=" + HttpUtility.UrlEncode(limit)
                + "&page=" + HttpUtility.UrlEncode(page);

            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Timeout = 15000;
            req.UserAgent = "Mozilla/5.0";

            string body;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            {
                body = sr.ReadToEnd();
            }
            ctx.Cache.Insert(cacheKey, body, null,
                DateTime.UtcNow.AddMinutes(10), Cache.NoSlidingExpiration);
            ctx.Response.Write(body);
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
