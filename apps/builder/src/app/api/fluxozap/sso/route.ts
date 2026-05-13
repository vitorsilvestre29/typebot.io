import prisma from "@typebot.io/prisma";
import { Plan, WorkspaceRole } from "@typebot.io/prisma/enum";
import { randomBytes } from "crypto";
import { NextResponse } from "next/server";

const SESSION_TTL_DAYS = 7;

type SsoRequest = {
  email?: string;
  name?: string | null;
  workspaceName?: string | null;
};

export async function GET(request: Request) {
  const url = new URL(request.url);
  const sessionToken = url.searchParams.get("sessionToken");
  const redirectPath = sanitizeRedirectPath(url.searchParams.get("redirectPath"));

  if (!sessionToken || !redirectPath) {
    return NextResponse.json({ error: "Invalid session handoff" }, { status: 400 });
  }

  const session = await prisma.session.findUnique({
    where: { sessionToken },
    select: { expires: true },
  });

  if (!session || session.expires < new Date()) {
    return NextResponse.json({ error: "Session expired" }, { status: 401 });
  }

  const publicBaseUrl =
    process.env.NEXTAUTH_URL ||
    process.env.NEXT_PUBLIC_BUILDER_URL ||
    request.headers.get("x-forwarded-host")?.replace(/^/, "https://") ||
    request.url;

  const response = NextResponse.redirect(new URL(redirectPath, publicBaseUrl));
  const cookieOptions = {
    httpOnly: true,
    sameSite: "none" as const,
    secure: process.env.NODE_ENV === "production",
    expires: session.expires,
    path: "/",
  };

  response.cookies.set("authjs.session-token", sessionToken, cookieOptions);
  response.cookies.set("__Secure-authjs.session-token", sessionToken, cookieOptions);

  return response;
}

export async function POST(request: Request) {
  const configuredSecret = process.env.FLUXOZAP_SSO_SECRET;
  const providedSecret = request.headers.get("x-fluxozap-secret");

  if (!configuredSecret || providedSecret !== configuredSecret) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as SsoRequest | null;
  const email = body?.email?.trim().toLowerCase();

  if (!email) {
    return NextResponse.json({ error: "Email is required" }, { status: 400 });
  }

  const name = body?.name?.trim() || email.split("@")[0];
  const workspaceName = body?.workspaceName?.trim() || "Fluxozap";

  const user = await prisma.user.upsert({
    where: { email },
    create: {
      email,
      name,
      emailVerified: new Date(),
      termsAcceptedAt: new Date(),
      onboardingCategories: [],
    },
    update: {
      name,
      emailVerified: new Date(),
      termsAcceptedAt: new Date(),
    },
  });

  const membership = await prisma.memberInWorkspace.findFirst({
    where: { userId: user.id },
    select: { workspaceId: true },
  });

  const workspaceId =
    membership?.workspaceId ??
    (
      await prisma.workspace.create({
        data: {
          name: workspaceName,
          plan: Plan.UNLIMITED,
          members: {
            create: {
              userId: user.id,
              role: WorkspaceRole.ADMIN,
            },
          },
        },
        select: { id: true },
      })
    ).id;

  let apiToken = await prisma.apiToken.findFirst({
    where: {
      ownerId: user.id,
      name: "Fluxozap",
    },
    select: { token: true },
  });

  if (!apiToken) {
    apiToken = await prisma.apiToken.create({
      data: {
        ownerId: user.id,
        name: "Fluxozap",
        token: `fz_${randomBytes(32).toString("hex")}`,
      },
      select: { token: true },
    });
  }

  const expires = new Date(Date.now() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
  const sessionToken = randomBytes(32).toString("hex");

  await prisma.session.create({
    data: {
      sessionToken,
      userId: user.id,
      expires,
    },
  });

  return NextResponse.json({
    sessionToken,
    expires: expires.toISOString(),
    apiKey: apiToken.token,
    workspaceId,
    userId: user.id,
  });
}

function sanitizeRedirectPath(value: string | null): string | null {
  if (!value) return null;

  try {
    const url = new URL(value, "http://fluxozap.local");
    if (url.origin !== "http://fluxozap.local") return null;
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return null;
  }
}
