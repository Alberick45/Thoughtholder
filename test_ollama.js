import { performance } from 'perf_hooks';

async function testOllama() {
  console.log("Testing Ollama API latency...");
  
  const startTags = performance.now();
  try {
    const tagsRes = await fetch('http://localhost:11434/api/tags');
    const tagsData = await tagsRes.json();
    console.log(`[API/TAGS] Time: ${(performance.now() - startTags).toFixed(2)}ms`);
    
    if (tagsData.models && tagsData.models.length > 0) {
      const model = tagsData.models[0].name;
      console.log(`Detected Model: ${model}`);
      
      const messages = [
        { role: 'system', content: 'You are Jarvis. Keep responses extremely concise.' },
        { role: 'user', content: 'hello' }
      ];
      
      console.log("Sending chat payload...");
      const startChat = performance.now();
      
      const response = await fetch('http://localhost:11434/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: model,
          messages: messages,
          stream: false,
          options: {
            num_predict: 120,
            temperature: 0.6
          }
        })
      });
      
      const chatData = await response.json();
      console.log(`[API/CHAT] Time: ${(performance.now() - startChat).toFixed(2)}ms`);
      console.log(`Response: ${chatData.message.content}`);
    } else {
      console.log("No models found.");
    }
  } catch (err) {
    console.error("Error communicating with Ollama:", err);
  }
}

testOllama();
