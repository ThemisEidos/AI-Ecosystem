$Code = @"
const body = `$json.body || `$json;

const command = body.command || '';
const message = body.message || '';

const routes = {
  '/status':  { route: 'status',   worker: 'router-health' },
  '/planner': { route: 'planner',  worker: 'planning-worker' },
  '/reporter':{ route: 'reporter', worker: 'reporting-worker' },
  '/timeline':{ route: 'timeline', worker: 'timeline-worker' },
  '/research':{ route: 'research', worker: 'research-worker' }
};

const matched = Object.keys(routes).find(prefix => command.startsWith(prefix));
const routeInfo = matched ? routes[matched] : {
  route: 'unknown',
  worker: 'manual-review'
};

let planner_output = null;

if (routeInfo.route === 'planner') {
  const response = await fetch('http://host.docker.internal:4000/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'local-llama',
      messages: [
        {
          role: 'system',
          content: 'You are a Personal Digital Analyst planning worker. PDA means Personal Digital Analyst. Be concise, implementation-focused, and operationally useful.'
        },
        {
          role: 'user',
          content: message
        }
      ]
    })
  });

  const data = await response.json();
  planner_output = data.choices?.[0]?.message?.content || data;
}

return [{
  json: {
    ok: true,
    command,
    message,
    ...routeInfo,
    planner_output,
    received_at: new Date().toISOString()
  }
}];
"@

$Code | Set-Clipboard
Write-Host "PDA planner router code copied to clipboard."
Write-Host "Paste it into the n8n Parse PDA Command Code node."
