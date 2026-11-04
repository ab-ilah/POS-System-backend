// Liveness probe. Returns no shop data and reads no secrets.
// Service-role credentials must never be added to this function or any bundle
// a browser could download. Server-only secrets belong in Edge Function secrets.

Deno.serve((request: Request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(JSON.stringify({ ok: false }), {
      status: 405,
      headers: {
        "content-type": "application/json; charset=utf-8",
        allow: "GET, HEAD",
      },
    });
  }

  const body = request.method === "HEAD" ? null : JSON.stringify({ ok: true, service: "pos-backend" });
  return new Response(body, {
    status: 200,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
});
