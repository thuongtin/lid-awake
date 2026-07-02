export async function onRequest(context) {
  const response = await context.next();
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) {
    return response;
  }

  const country = (context.request.cf && context.request.cf.country) || 'XX';
  const rewriter = new HTMLRewriter().on('head', {
    element(element) {
      element.append(`<script>window.__LID_AWAKE_GEO__="${country}";</script>`, { html: true });
    },
  });

  return rewriter.transform(response);
}
