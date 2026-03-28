FROM node:20-alpine AS base

RUN npm install -g npm@latest

# -----------------------------------------------------------------------------
# 2. Dependencies Stage: ลงของที่จำเป็น
# -----------------------------------------------------------------------------
FROM base AS deps
# libc6-compat จำเป็นสำหรับ Library บางตัวใน Node บน Alpine (เทียบเท่า build-essential)
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy package files (เทียบเท่า requirements.txt)
COPY package.json package-lock.json* ./

# 🔥 Highlight: ใช้ Cache Mount เหมือน uv pip
# npm จะเก็บ cache ไว้ที่ /root/.npm เรา mount ไว้เพื่อให้ครั้งหน้าไม่ต้องโหลดใหม่
RUN --mount=type=cache,target=/root/.npm \
    npm ci --legacy-peer-deps

# -----------------------------------------------------------------------------
# 3. Builder Stage: สร้างโปรเจกต์ (Next.js ต้อง Build ก่อน Run)
# -----------------------------------------------------------------------------
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .


# เพิ่มใน Dockerfile ก่อนบรรทัด RUN npm run build
# ARG OPENAI_MODEL_NAME=gpt-4o-mini
# ENV OPENAI_MODEL_NAME=$OPENAI_MODEL_NAME

# ⚠️ NEXT_PUBLIC_* จะถูก inline เข้าไปในโค้ด client-side ตอน build
# ต้องส่งค่าผ่าน --build-arg ตอน docker build
# ARG NEXT_PUBLIC_SUPABASE_URL
# ARG NEXT_PUBLIC_SUPABASE_PUBLISHABLE_OR_ANON_KEY
# ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
# ENV NEXT_PUBLIC_SUPABASE_PUBLISHABLE_OR_ANON_KEY=$NEXT_PUBLIC_SUPABASE_PUBLISHABLE_OR_ANON_KEY

# สั่ง Build (อย่าลืมตั้ง output: 'standalone' ใน next.config.js)
RUN npm run build

# -----------------------------------------------------------------------------
# 4. Runner Stage: ตัวรันจริง (Production)
# -----------------------------------------------------------------------------
FROM base AS runner
WORKDIR /app

# เพิ่ม dependencies ที่จำเป็นสำหรับ sharp และ native modules
RUN apk add --no-cache libc6-compat

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# สร้าง User เพื่อความปลอดภัย
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# ก๊อปปี้ไฟล์ที่ Build เสร็จแล้วมา
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

# ใช้ exec form (JSON) เพื่อให้ OS signals ส่งตรงไปที่ node process
CMD ["node", "server.js"]