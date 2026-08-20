const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    feedback: { type: 'string' },
    understanding_score: { type: 'number', minimum: 0, maximum: 1 },
    interest_delta: { type: 'number', minimum: -1, maximum: 1 },
    skill_delta: { type: 'number', minimum: -0.5, maximum: 0.5 },
    difficulty_next: { type: 'integer', minimum: 1, maximum: 3 },
    follow_up_prompt: { type: 'string' },
    follow_up_topic: { type: 'string' },
    content_quality: { type: 'number', minimum: 0, maximum: 1 },
    product_insight: { type: 'string' }
  },
  required: [
    'feedback',
    'understanding_score',
    'interest_delta',
    'skill_delta',
    'difficulty_next',
    'follow_up_prompt',
    'follow_up_topic',
    'content_quality',
    'product_insight'
  ],
  additionalProperties: false
};

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'Reviewer not configured' });

  const { question, answer, topic, difficulty, reveal, recentSignals } = req.body || {};
  if (!question || !answer) return res.status(400).json({ error: 'question and answer are required' });

  const input = [
    {
      role: 'system',
      content: [
        {
          type: 'input_text',
          text: `You are the adaptive learning reviewer inside an app called Instead. The app replaces doom scrolling with short, engaging, useful learning interactions. Review the user's answer, not the person. Be warm, concise, specific and educational. Never flatter weak answers. Distinguish knowledge, reasoning, creativity and interest. Generate a follow-up that is more valuable than the original question and naturally responds to the answer. Product insight should describe what this interaction suggests about how the app or question format could improve. Keep feedback under 70 words and follow-up under 35 words.`
        }
      ]
    },
    {
      role: 'user',
      content: [
        {
          type: 'input_text',
          text: JSON.stringify({ question, answer, topic, difficulty, reference_explanation: reveal || null, recent_signals: recentSignals || {} })
        }
      ]
    }
  ];

  try {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-5.2',
        reasoning: { effort: 'none' },
        input,
        text: {
          verbosity: 'low',
          format: {
            type: 'json_schema',
            name: 'instead_review',
            strict: true,
            schema: REVIEW_SCHEMA
          }
        }
      })
    });

    if (!response.ok) {
      const detail = await response.text();
      console.error('OpenAI error', response.status, detail);
      return res.status(502).json({ error: 'AI review failed' });
    }

    const data = await response.json();
    const text = data.output
      ?.flatMap(item => item.content || [])
      ?.find(item => item.type === 'output_text')
      ?.text;

    if (!text) return res.status(502).json({ error: 'No structured review returned' });
    return res.status(200).json(JSON.parse(text));
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'Reviewer error' });
  }
}
