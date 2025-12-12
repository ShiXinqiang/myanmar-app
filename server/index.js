const express = require('express');
const multer = require('multer');
const TelegramBot = require('node-telegram-bot-api');
const { Pool } = require('pg'); // 如果没有数据库，这行会报错，下面做了兼容
const fs = require('fs');
const cors = require('cors');

const app = express();
const upload = multer({ dest: '/tmp/' }); // Render/Railway 的临时目录
app.use(express.json());
app.use(cors());

// 环境变量（在 Render/Railway 后台填）
const TG_TOKEN = process.env.TG_TOKEN;
const TG_CHANNEL_ID = process.env.TG_CHANNEL_ID;
const DATABASE_URL = process.env.DATABASE_URL;

const bot = new TelegramBot(TG_TOKEN, { polling: false });
// 数据库连接池（如果有配置的话）
const pool = DATABASE_URL ? new Pool({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } }) : null;

// 1. 获取帖子
app.get('/api/posts', async (req, res) => {
    if (!pool) return res.json([]); // 无数据库时返回空
    try {
        const result = await pool.query('SELECT * FROM posts ORDER BY created_at DESC');
        const posts = await Promise.all(result.rows.map(async (post) => {
            if (post.tg_file_id) {
                try {
                    // 核心：每次请求时生成临时的 Telegram 下载链接
                    post.media_url = await bot.getFileLink(post.tg_file_id);
                } catch (e) { console.error(e); }
            }
            return post;
        }));
        res.json(posts);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// 2. 上传
app.post('/api/upload', upload.single('file'), async (req, res) => {
    try {
        const { text, username } = req.body;
        let tgFileId = null;
        let fileType = 'text';

        if (req.file) {
            const stream = fs.createReadStream(req.file.path);
            let sentMsg;
            if (req.file.mimetype.startsWith('video')) {
                sentMsg = await bot.sendVideo(TG_CHANNEL_ID, stream, { caption: text });
                tgFileId = sentMsg.video.file_id;
                fileType = 'video';
            } else {
                sentMsg = await bot.sendPhoto(TG_CHANNEL_ID, stream, { caption: text });
                tgFileId = sentMsg.photo[sentMsg.photo.length - 1].file_id;
                fileType = 'image';
            }
            fs.unlinkSync(req.file.path); // 清理垃圾
        }

        if (pool) {
            await pool.query(
                "INSERT INTO posts (username, content, tg_file_id, file_type) VALUES ($1, $2, $3, $4)",
                [username, text, tgFileId, fileType]
            );
        }
        res.json({ success: true });
    } catch (err) { 
        console.error(err); 
        res.status(500).json({ error: 'Upload failed' }); 
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Run on ${PORT}`));
