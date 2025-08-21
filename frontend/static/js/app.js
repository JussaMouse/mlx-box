document.addEventListener('DOMContentLoaded', () => {
    const chatLog = document.getElementById('chat-log');
    const chatInput = document.getElementById('chat-input');
    const sendBtn = document.getElementById('send-btn');

    const SERVER_URL = `http://${window.location.hostname}:8080/v1`;
    let modelName = '';
    let messages = [];

    const getModel = async () => {
        try {
            const response = await fetch(`${SERVER_URL}/models`);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();
            const models = data.data || [];
            
            const chatModel = models.find(m => m.id.toLowerCase().includes('instruct'));

            if (chatModel) {
                modelName = chatModel.id;
                addMessage('bot', `Connected to ${modelName}. Ready to chat!`);
                chatInput.disabled = false;
                sendBtn.disabled = false;
                chatInput.placeholder = 'Type your message...';
            } else {
                addMessage('bot', 'Could not find a suitable chat model. Please ensure a model with "instruct" in its name is running.');
                chatInput.placeholder = 'Error: No suitable model found.';
            }
        } catch (error) {
            console.error('Error fetching model:', error);
            addMessage('bot', 'Could not connect to the MLX server. Please ensure it is running.');
            chatInput.placeholder = 'Error: Could not connect to server.';
        }
    };

    const addMessage = (sender, text) => {
        const messageElement = document.createElement('div');
        messageElement.classList.add('message', sender);
        messageElement.textContent = text;
        chatLog.appendChild(messageElement);
        chatLog.scrollTop = chatLog.scrollHeight;
        return messageElement;
    };

    const sendMessage = async () => {
        const userInput = chatInput.value.trim();
        if (userInput === '' || modelName === '') {
            return;
        }

        addMessage('user', userInput);
        messages.push({ role: 'user', content: userInput });
        chatInput.value = '';
        chatInput.style.height = '24px';

        const botMessageElement = addMessage('bot', '...');

        try {
            const response = await fetch(`${SERVER_URL}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    model: modelName,
                    messages: messages,
                    stream: true,
                    max_tokens: 2048,
                }),
            });

            if (!response.body) {
                throw new Error('No response body');
            }
            
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let botResponse = '';
            botMessageElement.textContent = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                const chunk = decoder.decode(value, { stream: true });
                const lines = chunk.split('\n');

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const dataStr = line.substring(6);
                        if (dataStr.trim() === '[DONE]') {
                            break;
                        }
                        try {
                            const data = JSON.parse(dataStr);
                            const delta = data.choices[0].delta.content;
                            if (delta) {
                                botResponse += delta;
                                botMessageElement.textContent = botResponse;
                                chatLog.scrollTop = chatLog.scrollHeight;
                            }
                        } catch (e) {
                            // console.error('Error parsing stream data:', e);
                        }
                    }
                }
            }
            messages.push({ role: 'assistant', content: botResponse });

        } catch (error) {
            console.error('Error sending message:', error);
            botMessageElement.textContent = 'Error communicating with the server.';
        }
    };

    sendBtn.addEventListener('click', sendMessage);
    chatInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });
    
    chatInput.addEventListener('input', () => {
        chatInput.style.height = 'auto';
        chatInput.style.height = (chatInput.scrollHeight) + 'px';
    });

    getModel();
}); 