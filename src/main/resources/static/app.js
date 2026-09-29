async function callEndpoint(url) {
    const resultDiv = document.getElementById('result');
    resultDiv.innerHTML = '<em>Cagriliyor...</em>';
    try {
        const res = await fetch(url);
        const text = await res.text();
        resultDiv.innerHTML = text;
    } catch (e) {
        resultDiv.innerHTML = '<div class="error-box">Istek basarisiz: ' + e.message + '</div>';
    }
}

document.getElementById('btn-npe').addEventListener('click', () => callEndpoint('/api/npe-demo'));
document.getElementById('btn-warning').addEventListener('click', () => callEndpoint('/api/warning-demo'));
