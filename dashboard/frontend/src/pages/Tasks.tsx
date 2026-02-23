import { useState, useRef, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { listTasks, createTask, classifyPrompt, uploadImage } from '@/lib/api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { statusVariant } from '@/lib/status';
import VoiceInput from '@/components/VoiceInput';
import { ImagePlus, X } from 'lucide-react';

export default function Tasks() {
  const queryClient = useQueryClient();
  const { data: tasks, isLoading } = useQuery({
    queryKey: ['tasks'],
    queryFn: listTasks,
    refetchInterval: 5000,
  });

  const [showCreate, setShowCreate] = useState(false);
  const [prompt, setPrompt] = useState('');
  const [repo, setRepo] = useState('');
  const [baseBranch, setBaseBranch] = useState('main');
  const [repoAutoDetected, setRepoAutoDetected] = useState(false);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const imageInputRef = useRef<HTMLInputElement>(null);

  const classifyTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const scheduleClassify = useCallback((text: string) => {
    if (classifyTimerRef.current) clearTimeout(classifyTimerRef.current);
    if (text.length <= 20) return;
    classifyTimerRef.current = setTimeout(async () => {
      try {
        const result = await classifyPrompt(text);
        if (result.repo) {
          setRepo(result.repo);
          setRepoAutoDetected(true);
        }
      } catch {
        // silently ignore classify errors
      }
    }, 1000);
  }, []);

  const handlePromptChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setPrompt(e.target.value);
    setRepoAutoDetected(false);
    scheduleClassify(e.target.value);
  };

  const handleTranscript = (text: string) => {
    const next = prompt ? `${prompt} ${text}` : text;
    setPrompt(next);
    setRepoAutoDetected(false);
    scheduleClassify(next);
  };

  const handleRepoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setRepo(e.target.value);
    setRepoAutoDetected(false);
  };

  const handleImageSelect = (file: File | null) => {
    if (file) {
      setImageFile(file);
      const reader = new FileReader();
      reader.onload = (e) => setImagePreview(e.target?.result as string);
      reader.readAsDataURL(file);
    } else {
      setImageFile(null);
      setImagePreview(null);
    }
  };

  const handleImageDrop = (e: React.DragEvent) => {
    e.preventDefault();
    const file = e.dataTransfer.files[0];
    if (file && file.type.startsWith('image/')) {
      handleImageSelect(file);
    }
  };

  const createMutation = useMutation({
    mutationFn: async (data: { prompt: string; repo: string; base_branch?: string; image_url?: string }) => {
      return createTask(data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks'] });
      setShowCreate(false);
      setPrompt('');
      setRepo('');
      setBaseBranch('main');
      setRepoAutoDetected(false);
      setImageFile(null);
      setImagePreview(null);
    },
  });

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    let image_url: string | undefined;

    if (imageFile) {
      setUploading(true);
      try {
        const result = await uploadImage(imageFile);
        image_url = result.url;
      } catch (err) {
        setUploading(false);
        return;
      }
      setUploading(false);
    }

    createMutation.mutate({
      prompt,
      repo,
      base_branch: baseBranch || undefined,
      image_url,
    });
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Claude Tasks</h1>
        <Button
          variant={showCreate ? 'outline' : 'default'}
          onClick={() => setShowCreate(!showCreate)}
        >
          {showCreate ? 'Cancel' : 'New Task'}
        </Button>
      </div>

      {showCreate && (
        <Card className="mb-8">
          <CardHeader>
            <CardTitle>New Task</CardTitle>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleCreate}>
              <div className="space-y-4 mb-4">
                <div className="space-y-2">
                  <Label htmlFor="prompt">Prompt</Label>
                  <div className="flex gap-2 items-start">
                    <Textarea
                      id="prompt"
                      value={prompt}
                      onChange={handlePromptChange}
                      placeholder="Describe the coding task for Claude..."
                      required
                      rows={4}
                      className="flex-1"
                    />
                    <VoiceInput onTranscript={handleTranscript} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Image Attachment</Label>
                  <div
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={handleImageDrop}
                    className="border-2 border-dashed border-border rounded-lg p-4 text-center hover:border-muted-foreground/50 transition-colors cursor-pointer"
                    onClick={() => imageInputRef.current?.click()}
                  >
                    <input
                      ref={imageInputRef}
                      type="file"
                      accept="image/png,image/jpeg,image/gif,image/webp"
                      className="hidden"
                      onChange={(e) => handleImageSelect(e.target.files?.[0] || null)}
                    />
                    {imagePreview ? (
                      <div className="relative inline-block">
                        <img
                          src={imagePreview}
                          alt="Upload preview"
                          className="max-h-40 rounded-md border border-border"
                        />
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleImageSelect(null);
                          }}
                          className="absolute -top-2 -right-2 bg-destructive text-destructive-foreground rounded-full p-0.5"
                        >
                          <X className="size-3" />
                        </button>
                      </div>
                    ) : (
                      <div className="flex flex-col items-center gap-2 text-muted-foreground">
                        <ImagePlus className="size-8" />
                        <span className="text-sm">Drop an image here or click to select</span>
                        <span className="text-xs">PNG, JPG, GIF, WebP (max 10MB)</span>
                      </div>
                    )}
                  </div>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <div className="flex items-center gap-2">
                      <Label htmlFor="task-repo">Repository</Label>
                      {repoAutoDetected && (
                        <span className="text-xs text-muted-foreground">auto-detected</span>
                      )}
                    </div>
                    <Input
                      id="task-repo"
                      value={repo}
                      onChange={handleRepoChange}
                      placeholder="owner/repo"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="base-branch">Base Branch</Label>
                    <Input
                      id="base-branch"
                      value={baseBranch}
                      onChange={(e) => setBaseBranch(e.target.value)}
                      placeholder="main"
                    />
                  </div>
                </div>
              </div>
              <Button type="submit" disabled={createMutation.isPending || uploading}>
                {uploading ? 'Uploading image...' : createMutation.isPending ? 'Creating...' : 'Submit Task'}
              </Button>
              {createMutation.isError && (
                <p className="mt-2 text-destructive text-sm">
                  {(createMutation.error as Error).message}
                </p>
              )}
            </form>
          </CardContent>
        </Card>
      )}

      {isLoading ? (
        <p className="text-muted-foreground">Loading tasks...</p>
      ) : !tasks?.length ? (
        <p className="text-muted-foreground">No tasks yet.</p>
      ) : (
        <div className="space-y-3">
          {tasks.map((t) => (
            <Link key={t.id} to={`/tasks/${t.id}`}>
              <Card className="hover:border-muted-foreground/25 transition-colors">
                <CardContent className="py-4">
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-mono text-sm text-muted-foreground">
                      {t.id.slice(0, 8)}
                    </span>
                    <Badge variant={statusVariant(t.status).variant} className={statusVariant(t.status).className}>{t.status}</Badge>
                  </div>
                  <p className="text-sm line-clamp-2 mb-2">{t.prompt}</p>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    <span>{t.repo}</span>
                    <span>{t.base_branch}</span>
                    {t.preview_url && (
                      <span className="text-green-400">{t.preview_url}</span>
                    )}
                    <span className="ml-auto">
                      {new Date(t.created_at).toLocaleString()}
                    </span>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
